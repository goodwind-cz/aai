---
id: spec-selected-ci-conditional-sharding
type: spec
number: 240
status: done
frozen_sha256: 7d554b05e778134451ae80d0f4b99d4b4051432ec745ddc80eaba092f696b8a3
ceremony_level: 2
links:
  requirement: null
  rfc: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  intake: docs/issues/CHANGE-0215-selected-ci-conditional-sharding.md
  pr:
    - 486
  commits: []
---

# Conditional selected CI sharding

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0215-selected-ci-conditional-sharding.md
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
- Delivered foundation: docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md
- Full sharding: docs/specs/SPEC-0206-spec-ci-test-selection-narrowing-and-sharding.md
- Carry-forward: docs/specs/SPEC-0213-spec-post-validation-pushes-reuse-test-results.md
- Technology contract: docs/TECHNOLOGY.md

## Scope & Why

Baseline: main 89e7150e3bdf38c4c61bacacf27a8f9d07cd05af. Source inspection
confirms selected suites are validated and ordered longest-first but execute
on one runner with four workers. Full mode already has independent plan checks
and matrix execution. Deliver only conditional selected sharding, RFC Proposal
3.2. Body-edit evidence reuse is the next separate scheduling slice, followed
by the docs-audit Node pilot. Do not reopen the delivered foundation.

The baseline weights cite five successful main runs and explicit unsampled
fallbacks. They are scheduling estimates, not fresh measurements in this ride.
Planning ran no performance or runtime suite and makes no speed claim.

## Implementation strategy
- Strategy: loop
- Rationale: one focused extension to existing planning/checking/execution seams;
  observe every contract test failing before its implementation, then retain
  per-test green evidence and independent validation. No stored RED requirement.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: isolate PR-bound CI changes and fixtures from shared main.
- User decision: worktree (existing /aai-ship autopilot authorization; orchestrator records the fresh child binding).
- Base ref: main at 89e7150e3bdf38c4c61bacacf27a8f9d07cd05af
- Inline review scope: .aai/scripts/select-suites.mjs, .github/workflows/skill-suite.yml, tests/skills/lib/shard-plan-check.sh, tests/skills/test-aai-suite-select.sh, tests/skills/test-aai-ci-carry-forward.sh, tests/skills/lib/selected-scheduling-benchmark-check.mjs, tests/skills/suite-map.yaml, docs/product/ci-test-impact-selection.md, CHANGELOG.md, this spec, its intake and the parent RFC.
- Code review required: true. No protected L3 surface or new .aai file is planned.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Evidence |
|---|---|---|---|
| AC-001 / RFC 3.2 | Spec-AC-01 | V1 / TEST-001 | deterministic decision and boundary cases |
| AC-001 / conservative execution | Spec-AC-02 | V1 / TEST-002 | fallback/refusal cases and diagnostics |
| AC-002 / membership | Spec-AC-03 | V1 / TEST-003 | independent checker adversarial results |
| AC-003 / actual execution | Spec-AC-04 | V1 / TEST-004 | real framework start and result logs |
| AC-004 / CI seams | Spec-AC-05 | V2 / TEST-005 | gate truth table and anchor tests |
| AC-005 / measured improvement | Spec-AC-06 | V3 / TEST-006 | five paired raw runs and recomputed report |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the selected-plan CLI receives valid suites and complete usable weights, it SHALL deterministically choose one or two nonempty shards by the policy below, emitting existing SHARD records plus a machine-readable decision with predicted wall and runner seconds; exactly the deduplicated input set appears once. | done | docs/ai/tdd/selected-ci-conditional-sharding-V1-green.log | — | TEST-001 |
| Spec-AC-02 | WHEN weights are missing, unreadable, malformed, duplicate, nonfinite, or any selected suite has no weight, selected planning SHALL use one runner and emit a diagnostic; WHEN the input is empty, unreadable, unsafe, unknown or not a top-level runnable suite, it SHALL exit nonzero before execution. | done | docs/ai/tdd/selected-ci-conditional-sharding-V1-green.log | — | TEST-002 |
| Spec-AC-03 | WHEN an independent selected-plan check compares a plan, expected selected list and checkout, it SHALL exit 0 only for one or two nonempty contiguous shard IDs with every expected safe runnable suite exactly once; omissions, extras, duplicates, malformed records, fallback markers, invalid IDs and non-runnable names SHALL fail before extraction. | done | docs/ai/tdd/selected-ci-conditional-sharding-V1-green.log | — | TEST-003 |
| Spec-AC-04 | WHEN CI chooses selected mode, each active runner SHALL recheck the selected plan against its checkout and run exactly one existing framework invocation with repeated --skill data arguments and four workers; the union of actual starts SHALL equal the expected selection exactly once, with failure propagated and no bare full invocation. | done | docs/ai/tdd/selected-ci-conditional-sharding-V1-green.log | — | TEST-004 |
| Spec-AC-05 | The always-reporting required gate SHALL pass only after select and the chosen one-runner or two-runner aggregate succeed plus existing required dependencies; failed, cancelled, skipped or missing required results SHALL fail. Full-mode behavior, full-only carry-forward anchors, stable existing job names, PR concurrency and platform coverage SHALL retain their contracts. | done | docs/ai/tdd/selected-ci-conditional-sharding-V2-green.log | — | TEST-005 |
| Spec-AC-06 | The report SHALL contain five paired real executions of one fixed eligible selected workload at four workers per runner, with identical membership/runtime/hardware class, wall median/worst, summed runner-seconds and all exits/skips; it SHALL distinguish modeled policy values from measured values and disclose every slowdown or budget overrun. | done | docs/ai/tdd/selected-ci-conditional-sharding-V3-green.log; docs/ai/validation/selected-ci-conditional-sharding-benchmark.md | — | TEST-006 |

## Implementation plan

1. Extend select-suites.mjs with --selected-plan-from FILE, retaining --weights
   and --repo-root. Reuse existing ordering and SHARD representation. Keep
   existing --order-from, --shards and selection contracts unchanged.
2. Policy: order descending weight/name. Predict each runner's compute wall by
   assigning that ordered queue to four initially zero worker clocks, always
   the least-loaded clock (lowest index tie). One-runner wall W1 is max clock
   plus a fixed 30 s startup allowance. Build a two-runner candidate with the
   existing LPT total-weight bucket algorithm, lower shard index on ties; each
   bucket retains descending order and uses the same four-clock model. W2 is
   max of the two walls, R2 their sum, R1=W1. Choose two only if selected count
   >=8, W1>=120 s, W1-W2>=30 s, W2<=0.80*W1 and R2<=1.25*R1. Otherwise one.
   These are conservative engineering defaults, not measured startup promises.
   Report all inputs/estimates and decision reason. Missing/invalid weights
   disable expansion and retain safe existing ordering. Never allocate >2.
3. Add --check-selected PLAN SKILLS_DIR EXPECTED_LIST to the existing independent
   shell checker; share no selector implementation. Validate expected names too.
   Reject malformed SHARD lines and unexpected record types (explicitly allow
   the documented metadata records). Validate each requested shard is nonempty
   before extraction. Full --check and --extract interfaces remain compatible.
4. Keep skills-selected's current nonmatrix job/name for one runner. Add a
   separate skills-selected-sharded matrix job for the two-runner case; preserve
   the skipped old job name during full runs so ci-select.mjs's full-anchor
   proof stays valid without broadening it. Pass names/plans through env/files,
   never interpolate untrusted values into shell. Add the new job to gate needs
   and explicitly distinguish both selected paths. Pin checkout identity across
   selection and consumers or refuse a changed identity before execution.
5. Keep full planning/checks and full/main/nightly/ci-full behavior unchanged.
   Do not narrow suite-map dependencies or alter body edited events. Test the
   production shell step in disposable fixtures with real framework invocations,
   not merely regex matches of workflow text.
6. Measure the existing single-runner ordering versus candidate two-runner
   execution. Reuse the existing benchmark checker with an explicit variant
   schema if needed; retain the predecessor schema's validity. Record raw
   samples and arithmetic under docs/ai/validation/selected-ci-conditional-sharding-*.json/md.
   Product docs describe the policy and measured result without a guaranteed
   global speedup. No new runtime registry, telemetry service or dependencies.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-suite-select.sh | New CLI missing on baseline is RED; exact hand-calculated equal/unequal weights, tie order and below/at/above each threshold decide one/two runners; independently assert membership and repeated-call determinism. | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-suite-select.sh | New CLI baseline RED; valid suites with missing/malformed/duplicate/overflow/unreadable/incomplete weights retain one runner and all names; invalid/empty/traversal/nested-only input yields nonzero and zero framework starts, with valid positive control. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | Baseline lacks --check-selected; feed producer output to independent checker then corrupt missing/extra/duplicate/name/ID/record cases, expected list and checkout, including removed suite; exact offender and nonzero asserted. | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | Baseline workflow lacks selected sharding; execute real production steps against disposable cheap suites, assert per-runner invocation count, four-worker setting, exactly-once union, failing suite propagation and refusal before any start on bad plan. | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-ci-carry-forward.sh | Baseline gate lacks new job; execute gate truth table for single/sharded/full and required failure/cancel/skip/missing results; real full-mode anchor remains accepted, selected matrix success is never an anchor; retain concurrency and platform assertions. | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/lib/selected-scheduling-benchmark-check.mjs | Baseline checker rejects new two-runner measurement schema; real five-pair fixture passes new schema, insufficient pairs/mismatched membership/runtime/hidden skips or bad arithmetic fail; report compares observed costs to policy without converting predictions to observations. | green |

## Verification

V1: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-suite-select` exits 0; each TEST-001..004 case must execute, not skip.

V2: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-ci-carry-forward` exits 0 with TEST-005 and existing anchor regressions.

V3: `node tests/skills/lib/selected-scheduling-benchmark-check.mjs docs/ai/validation/selected-ci-conditional-sharding-benchmark.json` exits 0; independently recompute the report from the raw runs. Benchmark failures are remediation, never successful timings. At least one eligible large set and one ineligible small set must be represented in the policy evidence; five paired timings apply to the fixed large set. No p95 from five samples.

Before each behavior edit, observe its TEST row fail on the baseline/new test
(or a clearly identified deliberately corrupt input for safety controls), then
after the edit run it green. Transcript observations suffice for loop; do not
repeat the predecessor's missing-RED chronology. Tests/scratch experiments
use one independent disposable copy named in dispatch, never the shipping tree.
Run scope-selected regression and preserve the isolation tripwire.

Local acceptance establishes all six Spec-ACs and allows normal close-before-PR.
H1 and H2 below are mandatory delivery checks, explicitly pending at that point:
- H1: On candidate workflow code, observe a small selected run with exactly one
  active selected runner and a large eligible selected run with two, complete
  suite membership and successful gate. Record run/job IDs, tested SHA, plan,
  duration and actual runner seconds; a local fixture is not hosted evidence.
- H2: Observe full hosted regression on the candidate SHA including existing
  platform jobs and full gate; verify existing full anchors remain usable.
Before merge-readiness independently verify H1/H2. A fail enters remediation;
missing hosted evidence stays pending. Do not close the umbrella RFC. If measured
results exceed the modeled 25% runner budget or do not improve wall median,
report explicitly and tune/amend the eligibility policy before claiming an
operational improvement; local contract PASS alone is not such a claim.

## Evidence contract

Record child ref, AC/TEST IDs, exact commands, exits, base/candidate SHA, platform,
Node version, suite membership, worker/runner counts and relevant logs. Per-test
green evidence lives at docs/ai/tdd/selected-ci-conditional-sharding-*.log.
RED must be observed; storage is optional under loop. Independent Validation
returns one authoritative outcome report with its local versus hosted scope
explicitly stated. No implementation or runtime success is claimed by Planning.

## Registry review

Registry items closed by this scope: none.

follow-ups.mjs list was read on 2026-10-21. The selected-sharding half of
fu-lib-graph-narrowing-after-sharding is addressed, but the item stays open
because reverse-import narrowing is excluded. fu-shard-check-regex-arm-unpinned
and fu-shard-check-twin-basename concern the existing full checker; the new
selected checks test unsafe names explicitly but do not claim those full-mode
items closed. fu-framework-discover-exit-swallowed remains open: validation
before selected execution prevents this path here without changing standalone
framework discovery. fu-watchdog-3000-exceeds-ci-timeout remains open because
this slice retains existing job ceilings and process supervision.
