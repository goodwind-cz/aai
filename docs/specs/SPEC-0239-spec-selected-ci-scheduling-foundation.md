---
id: spec-selected-ci-scheduling-foundation
type: spec
number: 239
status: done
frozen_sha256: 9023057e6d1f02cd7357076503b2ab6c653341c27b4cf4ee67c94916662132ea
ceremony_level: 2
links:
  requirement: null
  rfc: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  intake: docs/issues/CHANGE-0214-selected-ci-scheduling-foundation.md
  pr: []
  commits: []
---

# Selected CI scheduling foundation

SPEC-FROZEN: true

## Links
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
- Predecessor: docs/specs/SPEC-0206-spec-ci-test-selection-narrowing-and-sharding.md
- Carry-forward boundary: docs/specs/SPEC-0213-spec-post-validation-pushes-reuse-test-results.md
- Technology contract: docs/TECHNOLOGY.md

## Scope & Why

Deliver only the first scheduling slice of the parent RFC: measured weight
refresh, longest-first execution of the existing selected set, and cancellation
of superseded read-only PR verification. This does not complete RFC phase 1,
which still owes conditional selected sharding and body-edit handling, or any
later RFC phase. Preserve the parent rollout as open.

Planning baseline is db7ce778c46c61f5d90f4124963556091047b7f5. Its repair of
pricing and close-reconcile supersedes the RFC's older observed pricing
failure; Planning has not rerun the runtime suite. The current workflow sorts
selected names alphabetically; the framework preserves repeated --skill order.
The current weights contain historical samples and missing discovered suites.

## Amendment — local acceptance and hosted delivery checks

The implementation acceptance criteria below are locally verifiable before
normal close-before-push. Spec-AC-05 accepts the workflow configuration, not an
unobserved GitHub scheduling outcome. Pre-PR Validation establishes every local
Spec-AC and explicitly records H1 and H2 as pending delivery checks. Closing the
implementation documents on that evidence does not assert hosted cancellation
or delivery completion. No draft-PR exception or gate bypass is introduced.

After PR creation, H1 SHALL demonstrate two runs of this candidate workflow for
the same PR: an older run is cancelled and its replacement succeeds, with an
unrelated run unaffected. H2 SHALL demonstrate successful full hosted regression
on the candidate SHA with the existing platform jobs. Record exact run/job IDs,
SHAs, conclusions and times; independently verify the observations and attach
them to the PR before any merge-readiness claim. Missing evidence stays pending;
failed evidence enters remediation. Neither merge nor parent rollout completion
is permitted while H1 or H2 remains pending. Local tests do not establish H1/H2.

This correction supersedes the earlier open-child/draft-PR suggestion, which
conflicted with canonical close-before-push. It changes the lifecycle boundary
without dropping either hosted requirement and is disclosed with signoff none.

## Implementation strategy
- Strategy: loop
- Rationale: bounded scheduling changes preserve existing behavior membership;
  write and observe failing tests for each new contract before a focused
  implementation pass. Existing full regression and independent validation
  remain mandatory. No mutation-gate or stored RED requirement is introduced.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound CI changes; shared main advanced during intake.
- User decision: worktree (authorized autopilot default under the owner's /aai-ship invocation; orchestrator records it).
- Base ref: main; baseline db7ce778c46c61f5d90f4124963556091047b7f5
- Inline review scope: .aai/scripts/select-suites.mjs, .github/workflows/skill-suite.yml, tests/skills/suite-weights.tsv, tests/skills/test-aai-suite-select.sh, tests/skills/test-aai-ci-carry-forward.sh, tests/skills/test-aai-product-docs.sh, tests/skills/suite-map.yaml, tests/skills/lib/selected-scheduling-benchmark-check.mjs, docs/product/ci-test-impact-selection.md, CHANGELOG.md, this spec and its intake.
- Code review required: true. No protected_paths_l3 file is in scope.

## Acceptance Criteria Mapping

| Parent requirement | Spec-AC | Verification | Evidence |
|---|---|---|---|
| Proposal 3.1: current duration weights | Spec-AC-01 | V1 / TEST-001 | source run IDs, SHAs, sample classifications, recount log |
| Proposal 3.1: selected longest-first | Spec-AC-02 | V1 / TEST-002 | ordered names and equality of input/output membership |
| Proposal 3: preserve safety fallback | Spec-AC-03 | V1 / TEST-003 | malformed/missing/tied-weight and invalid-input outputs |
| Proposal 3: actual execution boundary | Spec-AC-04 | V1 / TEST-004 and V2 / TEST-005 | real framework start log and gate result cases |
| Proposal 3.3: superseded PR cancellation | Spec-AC-05 | V1 / TEST-006 | workflow group cases; hosted H1 is a separate delivery check |
| Proposed success criteria: measurement honesty | Spec-AC-06 | V3 / TEST-007 | baseline/after measurement report with raw samples |

## Constitution deviations

Historical process exception, disclosed during remediation: strict per-row
pre-implementation RED was not established for all seven rows. TEST-001 has
transcript-observed exit 1 before weight refresh (after ordering implementation);
TEST-002 has a failing order assertion without a separately captured command
exit; TEST-003 never reached its own safety assertions because that combined
command stopped at TEST-002. TEST-004 and TEST-006 have transcript-observed
exit 1 for missing workflow ordering/concurrency. Original per-command times
and stored logs are unavailable. TEST-005 and TEST-007 negative probes were
after implementation. No new probe repairs that historical chronology.

For this existing implementation only, acceptance requires the disclosed
history plus timestamped adversarial controls against the recorded pre-change
snapshot/broken scratch variants, current positive checks, and fresh independent
Validation and Code Review. These controls are observed during remediation,
never pre-implementation RED. This is a contract exception with signoff none,
tracked by spec-amend; the original process shortfall remains visible.

Bounded regression repair includes product-doc TEST-012: retain live structural
checks and verify zero prose loss across the fixed SPEC-0105 initial migration
boundary while permitting later capability updates under its D3. No runtime
behavior or full regression requirement is removed.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | The shipped weights SHALL contain exactly one positive integer row per discovered runnable top-level suite and zero obsolete rows; each measured row names its successful run and SHA in a source record, and unsampled suites use the maximum measured weight with an explicit fallback label. Failed or skipped execution times SHALL NOT be passed off as successful measurements. | done | docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md | — | Refresh from current successful evidence, not invented timings |
| Spec-AC-02 | WHEN select-suites.mjs --order-from FILE receives a nonempty newline list of safe runnable selected names, it SHALL emit each name exactly once in descending weight, then bytewise name order for ties, without adding or removing a suite from the deduplicated input. | done | docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md | — | No changes to selection policy |
| Spec-AC-03 | WHEN weights are missing, unreadable or malformed, ordering SHALL retain every input suite and use name order with a stderr diagnostic; an individually missing weight SHALL use the maximum valid weight. Empty, unsafe, unknown or non-top-level suite names SHALL fail nonzero before framework execution. | done | docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md | — | No accidental bare full invocation |
| Spec-AC-04 | WHEN selected CI runs, the workflow SHALL feed the ordered list to one existing framework invocation with repeated --skill arguments and AAI_TEST_PARALLEL=4; the existing aggregate gate SHALL fail on selection/ordering failure, suite failure, or a missing required job, and existing full-mode membership, carry-forward identities and job names SHALL remain valid. | done | docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md | — | Cross producer/consumer seam |
| Spec-AC-05 | The workflow SHALL define a concurrency group containing workflow identity and PR number for PR events, enable cancellation only for PR verification, and give non-PR events distinct run identities. Tests SHALL verify same-PR equality, different-PR inequality, non-PR uniqueness, and exclusion of release workflows. | done | docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md | — | Local configuration acceptance; H1 separately required for hosted cancellation claim |
| Spec-AC-06 | The report SHALL contain five paired baseline/after samples for a fixed selected workload on the same hardware/runtime, sample count, median, worst wall time, summed runner-seconds, suite membership, exit/skip outcomes, and fixture/startup/execution/cleanup timing where observable; unobservable components SHALL be marked unavailable. The change SHALL add zero runners and preserve four workers per selected job. | done | docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md | — | No guaranteed global speedup from this slice |

## Implementation plan

1. Before editing runtime behavior, capture the actual base SHA and successful
   CI logs. Select the latest five successful full runs on main if available;
   otherwise use successful per-suite samples from recent runs, reporting their
   count. Compute each suite's rounded median seconds, floor 1. Missing suites
   take the maximum observed weight and are listed as unsampled. Keep raw log
   citations under docs/ai/validation; document the derivation alongside the
   existing TSV header. No permanent telemetry service or manifest is added.
2. Extend the existing selector with --order-from FILE (and existing --weights,
   --repo-root options), reusing its weight parser and ordering semantics.
   stdout is only safe suite names; diagnostics go to stderr. Existing selector
   modes and --shards output retain their contracts. No general dependency graph.
3. In the selected workflow job, materialize names through env/file data,
   invoke ordering, then execute the framework exactly once. Keep job names
   consumed by ci-select.mjs unchanged. Preserve the full path and checker.
4. Add PR-specific read-only verification concurrency to skill-suite.yml,
   with event/run identity for non-PR groups. Audit every job in this workflow
   for external mutation before applying workflow-level cancellation; if any
   externally mutating job exists, isolate concurrency to read-only jobs.
   Do not change release.yml or publication behavior. Edited events continue
   their current behavior in this slice.
5. Run the paired benchmark on identical suite inputs, concurrency and runtime;
   baseline uses the recorded base implementation, after uses the candidate.
   Record queue order and suite outcomes. Benchmark specimens live in an
   independent scratch copy; never modify shipping history or tracked files
   to obtain baseline. Explain any slowdown; do not rename a simulation a run.
6. Update product documentation and release notes with the actual limited
   behavior. No additional .aai file or prompt addition is planned. If either
   becomes necessary, amend scope for PROFILES classification or prompt ledger
   true-up before introducing it.

The first implementation command should reproduce TEST-002 failure on the
pre-change CLI, then establish each other row's RED with its stated adversarial
case. Ordering must not weaken the existing suite-map dependency closure,
full-on-unknown behavior, or the shipping-tree isolation tripwire.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-suite-select.sh | Recount discovered suites against TSV; stale/missing/duplicate/nonpositive row fixtures must fail the refresh audit; inspect raw sample provenance including explicit unsampled fallback. | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-suite-select.sh | Invoke order CLI with nonalphabetical weights, ties and repeated names; exact order and unique membership asserted; baseline lacks new mode and must fail. | green |
| TEST-003 | Spec-AC-03 | unit | tests/skills/test-aai-suite-select.sh | Missing/malformed/unreadable weights preserve membership with diagnostics; unknown weight uses max; empty, traversal, shell token, unknown and nested-only names fail. | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | Real framework in its independent test fixture runs cheap instrumented suites in supplied queue order; every intended suite starts exactly once, invalid name prevents any start; preserve timeout/isolation wrapper. | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-ci-carry-forward.sh | Evaluate real workflow wiring and existing carry-forward tests: fixed job names, selected/full gate cases including failed/missing jobs; full shard membership checker still runs; names are consumed as data. | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-suite-select.sh | Workflow concurrency expression scenarios for same/different PRs, push-main, nightly, dispatch and release establish the local configuration contract; H1 separately verifies hosted cancellation after PR creation. | green |
| TEST-007 | Spec-AC-06 | integration | docs/ai/validation/selected-ci-scheduling-foundation-benchmark.md | Recompute sample count, median, worst and runner-seconds from ten raw paired records; reject fewer than five pairs, mismatched runtime/membership and unlabelled skips. Check same runner/worker allocation. | green |

## Verification

V1: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-suite-select` must exit 0. Target new cases by the suite's existing single-function interface while developing; the final run covers the full suite.

V2: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-ci-carry-forward` must exit 0. Post-PR and before merge, hosted skill-suite results on the candidate SHA must demonstrate aggregate success and the same-PR cancellation pair. These hosted observations are explicitly pending at the pre-PR local Validation boundary. Static workflow assertions alone do not prove GitHub scheduling.

V3: `node tests/skills/lib/selected-scheduling-benchmark-check.mjs docs/ai/validation/selected-ci-scheduling-foundation-benchmark.json` (new test-only checker) must exit 0, validating TEST-007's raw record schema and arithmetic. Store the human interpretation beside it. The checker verifies observations, not a fabricated acceleration threshold.

Also run existing selector full-shard membership checks, spec lint, and the
scope-selected validation suites. Because CI changes scheduling, run one full
hosted regression before merge; existing platform coverage is retained. No
runtime version floor, OS support, gate freshness policy or test isolation
contract changes in this slice.

## Evidence contract

Each record names child ref selected-ci-scheduling-foundation, Spec-AC and TEST
ids, exact command, exit, base/candidate SHA, platform/runtime, and artifact.
Observed RED is normally required per row; the historical exception and substitute
checks for this existing implementation are disclosed above; loop storage is optional. Store green logs
under docs/ai/tdd/selected-ci-scheduling-foundation-*.log and measurements under
docs/ai/validation/. Validation independently reads raw records and checks the
real selector-to-framework seam. A Validation PASS requires its authoritative
outcome report identifying whether it is the pre-PR local scope or the final hosted completion scope; implementation may not claim hosted evidence from local probes.

## Registry review

The existing item fu-lib-graph-narrowing-after-sharding remains open: this slice
orders one selected runner and does not deliver selected sharding or graph
narrowing. fu-framework-discover-exit-swallowed remains open: the new ordering
mode refuses invalid names before dispatch but does not repair the framework's
standalone discovery behavior. fu-shard-check-regex-arm-unpinned and
fu-shard-check-twin-basename remain open: no full-plan checker change here.
fu-sync-seed-cache-no-ci-gain remains open: weights record observations without
claiming a sync performance fix. Registry source: follow-ups.mjs list,
2026-10-20 UTC.

Registry items closed by this scope: none.

Remediation integration baseline: `35f1448410a3e9a813367a60defeb6551199db7f`
(PR #483). Historical benchmark/base observations remain at their recorded SHA;
they are not restamped as final-tree or hosted measurements.
