---
id: spec-docs-audit-node-test-pilot
type: spec
number: 241
status: done
frozen_sha256: 2428317006c828bb226cc11a4e93bddd5d3d2ba987837b8dc9fc8a0d33e5ee38
ceremony_level: 2
links:
  requirement: docs-audit-node-test-pilot
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Docs-audit body-lint Node test pilot

SPEC-FROZEN: true

## Links

- Requirement: [Docs-audit Node test pilot](../issues/CHANGE-0216-docs-audit-node-test-pilot.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md), bounded phase 2 child.
- Technology contract: docs/TECHNOLOGY.md.
- Baseline: `a15065159a26af9cdbe6d57a193de9ca35da7389`.

## Implementation strategy

- Strategy: loop
- Rationale: relocate five existing behavior test groups onto an already exported
  pure function; no production behavior change is needed. Preserve assertions
  before accepting measurements. Observe deliberate semantic corruption and
  wiring failure, then restore only the disposable copies. Per-test green
  evidence and independent validation are required. This is not a new test
  framework or a production parser rewrite.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the work is PR-bound and removes tests while benchmark and
  mutation experiments need disposable copies. This is a test-location refactor,
  not a runtime or data migration and touches no protected L3 surface.
- User decision: worktree
- Decision authority: the owner's continuing aai-ship autopilot authorization
  applies the recommended-worktree default; Preparation records the concrete
  branch and path. No routine preference question is outstanding.
- Base ref: main, with the immutable baseline above used for comparisons.
- Worktree branch/path: assigned by Implementation Preparation.
- Inline review scope: tests/skills/test-aai-docs-audit.sh;
  tests/skills/lib/docs-audit-body.test.mjs; tests/skills/suite-map.yaml;
  docs/analysis/docs-audit-node-test-pilot.md; docs/USER_GUIDE.md;
  docs/product/ci-test-impact-selection.md; this spec; its intake;
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md.
- Code review required: true. Do not broaden to wrapper, scheduler, runtime,
  production parser, hook, or workflow changes to make measurements pass.

## Scope and design

Call `lintBody` from `.aai/scripts/lib/docs-audit-core.mjs` using `node:test`
with `node:assert/strict`. The export already accepts a Markdown string and
returns findings with rule, original one-based line and detail. It performs no
filesystem/Git work. Import the library, never `.aai/scripts/docs-audit.mjs`:
the CLI runs main on import. No production changes or new dependency are needed.

Create `tests/skills/lib/docs-audit-body.test.mjs`. The fast path builds strings
in memory, with no filesystem fixtures, repository clone, Git initialization,
child-process call, or call to `runAudit`. Node's own test-runner process and the
canonical wrapper are allowed; the zero-child-process requirement applies to
the test cases and function calls, not the runner's implementation. The wrapper
already scopes automatic cloning to shell suite invocations, so a direct
`node --test` command needs no isolation bypass or wrapper change.

Keep complete fixture strings, including frontmatter and blank lines, from the
five selected functions. Use stable case names carrying the legacy suffix and
assert expected findings directly. Do not synthesize expected output by calling
another production parser or by copying its algorithm. Assert exact rule/line
sets and zero-finding controls, adding detail checks where useful. Repeat the
same fixtures with CRLF line endings as a small additional boundary check;
count those additions separately from migrated assertions in the benchmark.
Malformed inputs here mean the existing unclosed fences and frontmatter-only
strings, not a new policy for arbitrary object arguments.

Invoke the Node file once during the existing Bash suite's normal `main`, after
its dependency check and before expensive fixture setup, with failure propagated.
Use one named Bash entrypoint for this invocation so the existing single-function
selector can exercise it. Preserve that selector and all other functions and
registrations. Do not introduce a second discoverable suite or change scheduler
weights merely to get the new file selected: add its exact path under the
existing `aai-docs-audit` suite-map row. The suite remains in the always-on core.
Existing local framework, selected CI, selected sharded CI and full CI then
consume the same entrypoint. No workflow edit is expected.

## Migration map fixed before measurement

Source line numbers below refer to the immutable baseline and aid inspection;
function names and assertion identities are the binding references. Each named
function body and its normal-main registration must disappear after migration.
The report must reconcile every clause below to a named Node test or retained
CLI assertion, including clauses that were repeated across legacy groups.

| Map | Legacy function in tests/skills/test-aai-docs-audit.sh | Semantic assertions and Node case family | Retained boundary coverage |
|---|---|---|---|
| M1 | test_change0007_lint_unbalanced_fence, lines 4100–4124 | Preserve complete SPEC-7702 fixture; an unclosed backtick fence produces unbalanced-fence at original opening line 11. Node family unbalanced_fence. | Non-strict lint command exits 0 remains in lint_stray_markup; CLI strict/report behavior stays in lint_promotion_pair. |
| M2 | test_change0007_lint_placeholder, lines 4125–4155 | Preserve SPEC-7703; `SPEC-XXXX` on line 10 and all-caps angle token on line 11 produce template-placeholder; mixed-case angle prose produces no finding, specifically no line 12 finding and no detail containing why isolation. Node family placeholder. The legacy input contains both PLACEHOLDER and TODO_FILL on one line; preserve that input and existing first-match behavior. | Non-strict exit 0 remains in lint_stray_markup; printed rule/path/line remains independently exercised there. |
| M3 | test_change0007_lint_negative_controls, lines 4156–4196 | Preserve both SPEC-7704 and SPEC-7705; ordinary prose yields zero findings; fenced markup, angle placeholders and `SPEC-XXXX` yield zero; the same tokens in inline code yield zero; aggregate is zero. Node family negative_controls. Pair with the dirty M2/M5 controls so a function returning an empty array cannot pass. | Zero-count rendering is exercised by a compact clean assertion added to retained lint_stray_markup using its existing fixture, with the dirty rendering control kept. |
| M4 | test_change0007_lint_degenerate_fixtures, lines 4197–4261 | Preserve all five SPEC-7706 through SPEC-7710 fixtures: frontmatter with empty body, frontmatter without final newline, four-backtick wrapper around a three-backtick example, balanced tilde fence, open tilde fence. First four do not throw and yield zero; aggregate exactly one finding, unbalanced-fence at original line 10 of SPEC-7710. Node family degenerate_fixtures. | Retained CLI smoke observes successful dirty and clean invocations; body-file predicate retains missing/clean/dirty 2/0/1 behavior. |
| M5 | test_change0007_lint_span_edges, lines 4605–4661 | Preserve both SPEC-7920 and SPEC-7921; multiline inline span masks its interior; same-line triple-backtick pair is not an unclosed fence; live markup after it is still found as stray-tool-markup at line 12; exactly one finding across both, none attributed to SPEC-7920. Node family span_edges. | Existing stray-markup rendering remains and tests findings reaching stdout. |

Legacy non-strict exit-0 checks in M1–M5 are CLI semantics, not pure-function
assertions. Consolidate these repeated contract checks into the retained smoke
and explicitly mark that consolidation in the report; do not claim Node asserts
an exit code. Keep `test_change0007_lint_stray_markup`'s dirty fixture, exit 0,
Body lint heading, exact relative paths/lines 11 and 12 with rule id, and nonzero
ordinary check digest unchanged; extend it only with a clean zero-count control.
This is intentional boundary sampling, with each distinct parser input covered
in Node, rather than retaining five redundant repository-backed executions.

Retain unchanged bodies/registrations for `test_change0007_lint_promotion_pair`,
`test_change0007_lint_body_file_predicate`, `test_change0007_hook_body_lint`,
`test_change0007_hook_config_staged`, `test_change0007_hook_space_filename`,
`test_change0007_regression`, and every other unmigrated function. In particular
keep the real-repository CRLF, false-open, duplicate-id, AC-table and index corpus
checks. Do not split always-on content/engine validation in this child.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01: inspect the tracked report and frozen M1–M5
  map against `git show a15065159a26af9cdbe6d57a193de9ca35da7389:tests/skills/test-aai-docs-audit.sh`.
  Every semantic clause has a named replacement or retained boundary assertion,
  with zero unexplained omissions and the baseline identified before samples.
- Intake AC-002 maps to Spec-AC-02: the canonical fast command below exits 0,
  all five named families execute, findings match M1–M5 and CRLF controls, and
  source inspection finds zero test-case process/Git/filesystem fixtures and
  zero package dependencies added.
- Intake AC-003 maps to Spec-AC-03: the five old bodies and registrations are
  absent, all other cases remain reachable, the normal framework executes the
  Node tests, and a deliberate failing Node assertion makes that path nonzero.
- Intake AC-004 maps to Spec-AC-04: the report contains five successful paired
  matched-workload B/F samples, median/worst/wall/runner work and setup
  disclosures, and a lower matched-workload median. The ordinary integration
  suite has one successful before and one after correctness run, with individual
  timing observations only; no ordinary-suite median or speedup claim. Report whether every fast
  sample is at most 10 seconds; that RFC hypothesis is not a guaranteed budget.
- Intake AC-005 maps to Spec-AC-05: retained CLI and corpus checks pass through
  isolation, independent mutation and registration checks pass, shipping inputs
  remain unchanged, and documentation names the executable commands accurately.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the migration map is reconciled, every M1–M5 assertion SHALL have one named logic owner or retained CLI owner with zero unexplained omissions. | done | docs/ai/reports/VALIDATION-20261021T134901Z-docs-audit-node-test-pilot.md; docs/ai/tdd/docs-audit-node-test-pilot/fixture-compare.log; docs/ai/tdd/docs-audit-node-test-pilot/migration-map-check.log; docs/analysis/docs-audit-node-test-pilot.md | — | Independent Validation PASS; dual Code Review PASS. |
| Spec-AC-02 | WHEN the Node file runs, all mapped parser inputs SHALL produce their specified findings without test-case subprocesses, Git or filesystem fixtures. | done | docs/ai/reports/VALIDATION-20261021T134901Z-docs-audit-node-test-pilot.md; docs/ai/tdd/docs-audit-node-test-pilot/focused-first.log; docs/ai/tdd/docs-audit-node-test-pilot/mutation-empty-result.log | — | Independent Validation PASS; dual Code Review PASS. |
| Spec-AC-03 | WHEN the ordinary docs-audit suite runs, it SHALL execute the Node cases once and propagate a failing assertion; the five replaced Bash functions SHALL be absent. | done | docs/ai/reports/VALIDATION-20261021T134901Z-docs-audit-node-test-pilot.md; docs/ai/tdd/docs-audit-node-test-pilot/integration-after-aai-docs-audit.log; docs/ai/tdd/docs-audit-node-test-pilot/mutation-framework-propagation.log; docs/ai/tdd/docs-audit-node-test-pilot/selector.log | — | Independent Validation PASS; dual Code Review PASS. |
| Spec-AC-04 | WHEN five comparable pairs are measured, the tracked report SHALL expose every sample and show a lower matched-workload median, with the ten-second hypothesis explicitly evaluated. | done | docs/ai/reports/VALIDATION-20261021T134901Z-docs-audit-node-test-pilot.md; docs/ai/tdd/docs-audit-node-test-pilot/paired-manifest.json; docs/ai/tdd/docs-audit-node-test-pilot/integration-before.json; docs/ai/tdd/docs-audit-node-test-pilot/integration-after.json; docs/analysis/docs-audit-node-test-pilot.md | — | Independent Validation PASS; dual Code Review PASS. |
| Spec-AC-05 | WHEN retained CLI/corpus and independent checks run, they SHALL preserve existing contracts and detect deliberate semantic corruption with zero shipping-input changes. | done | docs/ai/reports/VALIDATION-20261021T134901Z-docs-audit-node-test-pilot.md; docs/ai/tdd/docs-audit-node-test-pilot/integration-after-aai-docs-audit.log; docs/ai/tdd/docs-audit-node-test-pilot/mutation-span-masking.log; docs/ai/tdd/docs-audit-node-test-pilot/doc-command-check.log | — | Independent Validation PASS; dual Code Review PASS. |

## Implementation plan

1. Create a disposable baseline checkout/copy from the pinned commit with an
   independent Git directory; inventory the selected fixture strings and
   assertions before any timing accepted. Preserve raw inventory and commands.
2. Implement the Node groups, observe a missing-test or deliberately corrupted
   behavior failure, then remove the five Bash functions and registrations.
   Add the single normal-main Node invocation, selection mapping, and clean
   rendering control. Keep the production files byte-identical to baseline.
3. Execute focused Node, CLI, registration, failure-propagation and isolation
   checks. Perform mutations in one disposable copy, never the shipping tree.
4. Measure the fixed workloads below and publish the tracked report; update the
   existing user guide and CI-selection product page with both commands and the
   limited claim (body-lint logic only, not full audit/corpus).
5. Independent Validation reconciles the old source to the new cases, reruns
   the declared checks and challenges at least one logic defect independently.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | inspection | docs/analysis/docs-audit-node-test-pilot.md | Reconcile every M1–M5 clause, names, fixtures and retained CLI ownership against immutable baseline; list exact removed line and registration counts. | Delete the line-12 live-markup assertion from a disposable Node copy; reconciliation must identify the missing M5 clause. | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/lib/docs-audit-body.test.mjs | Run all five named families over baseline strings and CRLF counterparts; assert exact rule/line sets and positive/negative controls. | Make lintBody return an empty array in a disposable copy; dirty controls must fail. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | Check removed definitions/registrations, unchanged other functions, node entrypoint once in normal main, selector mapping, successful isolated framework run and failing-Node propagation through it. | Replace one expected Node finding line with an incorrect value in a disposable copy; the real framework docs-audit run must exit nonzero. | green |
| TEST-004 | Spec-AC-04 | performance | docs/analysis/docs-audit-node-test-pilot.md | Collect and calculate five paired matched-cluster samples; run ordinary integration once before and once after for correctness with individual timing observations only. Identify setup, assertion inventory, elapsed/runner seconds and hypothesis result. | Recompute medians from raw samples and reject a report with an altered sample or excluded failed attempt. | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | Retained dirty/clean CLI rendering, report-only/strict, file-predicate, hooks and corpus cases pass; capture source hashes/status and scoped cleanup. | In disposable core disable multiline inline-span masking or swallow the live token following the same-line span; M5 must fail. | green |
| TEST-006 | Spec-AC-05 | inspection | docs/USER_GUIDE.md | Verify guide and CI product page commands execute at the reported head, distinguish focused versus complete coverage, keep framework and runtime contracts unchanged. | Point documented fast command at a nonexistent test file in a disposable doc copy; command verification must reject it. | green |

## Benchmark design and verification commands

Freeze the map and command classes before measuring; no post-hoc choice of
faster inputs, smaller assertion sets, timeout exclusions, or successful runs.
Use the same host, Node binary/version, Bash version, environment, wrapper and
serial execution width for before and after. Record OS/architecture, Git and
Node versions, immutable baseline and candidate tree identity, UTC timestamps,
command text, exit codes, raw wall seconds, and emitted test counts. Do not
claim a new runtime floor: CI currently selects Node 20; verify there as well
as locally. No p95 claim from five samples.

The focused after command (F) is:

```sh
bash .aai/scripts/aai-run-tests.sh node --test tests/skills/lib/docs-audit-body.test.mjs
```

The ordinary integration command (I), before and after, is:

```sh
AAI_TEST_PARALLEL=1 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-docs-audit
```

Matched before (B): a disposable Bash driver sources the pinned original suite,
assigns TEST_DIR to an absolute mktemp directory, then calls M1, M2, M3, M4, M5
once in that fixed order. Do not call setup_fixture: it adds unrelated corpus
work; the selected functions need TEST_DIR and setup_iso_repo only. Invoke the
driver through `bash .aai/scripts/aai-run-tests.sh bash <absolute-driver-path>`
from the disposable baseline root. Assert the temp path is nonempty/absolute.
Archive its exact source with the evidence. No source edits to the baseline are
allowed. This retains the legacy five Git fixtures, five CLI launches and all
old assertions rather than benchmarking an extracted reimplementation.

Run one declared untimed warm-up for B and F, then five paired B/F runs.
Alternate before/after order each pair to limit drift. Run I once before and
once after as correctness checks, with individual timing observations only.
No I warm-up or repeated I benchmark is required; do not claim an ordinary-suite
median or speedup. Independent Validation still performs its fresh integration
run as needed for its verdict.
Use five successful samples for estimates; disclose every failed/timed-out
attempt and rerun the whole affected pair after diagnosis. Nonzero runs never
count as faster passes. Each matched before sample includes fixture creation,
Git initialization, module copies and cleanup. Each after includes wrapper,
Node runner startup and test execution. Setup of the two reusable checkouts is
measured and disclosed separately. I samples include their existing framework
isolation/setup costs on both sides; report both total wall and summed suite
runner duration from existing logs. Matched runs are serial so their worker
wall time is runner-seconds; disclose wrapper overhead separately when available.
Count Git fixture creations and CLI child launches from the fixed driver/source,
and distinguish these static counts from instrumented measurements. Report the
extra CRLF test workload rather than pretending it existed before.

Use a monotonic external timer and preserve stdout/stderr, sample JSON/CSV and
the driver under docs/ai/tdd/docs-audit-node-test-pilot/; embed raw numeric rows,
commands, tree identities and summary in the tracked analysis report. The report
also contains baseline/candidate Bash and Node line counts, removed bodies and
registration count, added glue lines and net changes. A lower B/F median is the
pilot speed evidence. The single I observations establish successful execution
and disclose aggregate cost; they do not support a suite-wide speed conclusion.
Investigate actual correctness failures and timeouts without turning ordinary
integration into a repeated benchmark. Ten seconds is evaluated against all five F samples
with median and worst reported; a miss is disclosed, never silently loosened.

Registration check: run `node .aai/scripts/check-test-registration.mjs tests/skills`;
require exit 0 and no orphan findings. Feed the Node test path alone to `select-suites.mjs --files-from` and
require aai-docs-audit in the selected set, with no unknown-path full fallback.
The framework path must visibly execute the named Node cases; a source string
mention or an empty/skipped test run is not execution evidence.

All execution uses the canonical wrapper with explicit bounded timeout
(`AAI_TEST_TIMEOUT=120` for focused cases, `900` for the ordinary suite), one
worker, and scoped post-step `aai-reap-tests.sh` using that step's workspace and
start epoch. Keep pre/post shipping source/status snapshots. Wrapper/framework
telemetry appends are allowed and named; source/docs/INDEX and unrelated drafts
are not. Never bypass isolation for the ordinary suite. Do not run broad full
shipping tests for the benchmark. Hosted selected/full regression obligations
remain the existing PR gates; this child adds no new CI job.

## Evidence contract

Per TEST and Spec-AC, retain command, exit, source identity, output and evidence
path in docs/ai/tdd/docs-audit-node-test-pilot/. Each AC status Evidence cell
must cite a docs/ai/tdd log at handoff. Strategy loop requires per-test green
runs and observed RED proof; storing the short mutation/failure outputs is
recommended, not the tdd mutation-gate ceremony. TEST-002 and TEST-005 must
observe distinct semantic mutations failing in the disposable copy, and
TEST-003 must observe the real framework propagate the deliberate failure.
Independent Validation supplies its authoritative outcome report and its own
assertion-preservation review. Passing Planning checks does not attest any
implementation, timing or platform result.

## Risks and rollback

- A new Node test may pass while omitted from CI: normal-main wiring and the
  deliberate failure through the real framework decide this, not grep alone.
- Fixture text simplification can lose original line/format coverage: retain
  complete baseline strings and compare the frozen map before accepting timing.
- Aggregate timing can be noisy: paired fixed workloads and explicit setup and
  worker accounting bound the claim; no guessed seconds or token savings.
- Existing corpus suites can write to their checkout: run through independent
  isolation and serialize audit-touching tests; never benchmark against the
  user's dirty main checkout. Preserve unrelated INDEX and old intake drafts.
- Rollback is one scoped revert restoring the five functions/registrations,
  removing their Node owner/invocation/map entry and updating command docs as a
  unit. Do not ship duplicated logic owners as a rollback halfway state.

## Registry disposition

The open fu-docs-audit-suite-has-no-selector describes a broader historic
selector problem; this pilot preserves the current single-function dispatch and
does not claim a comprehensive selector repair. fu-runmain-runs-main-on-import
remains open because the pilot imports only the existing library, not the CLI.
fu-prompt-diet-fixture-real-root-race remains open because suite-wide concurrency
and bare invocation hazards are outside this five-case test relocation; isolated
execution is mandatory here. Other docs-audit findings concern delivery/status,
config and close logic, which this child does not touch.

Registry items closed by this scope: none.
