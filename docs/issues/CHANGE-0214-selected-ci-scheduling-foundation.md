---
id: selected-ci-scheduling-foundation
type: change
number: 214
status: done
capability: ci-test-impact-selection
user_visible: true
links:
  rfc: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  spec: docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md
  pr: []
  commits: []
---

# Selected CI scheduling foundation

## Summary

Deliver the first bounded scheduling slice of the smaller Node core RFC:
refresh suite weights from successful CI observations, execute the existing
selected suite set longest-first, and cancel superseded read-only verification
for the same pull request. This child does not complete the umbrella RFC or its
first rollout phase.

## Motivation / Business Value

Selected CI currently alphabetizes suites despite having duration weights;
the full-run weights also lag recent suite costs. Better queue order can reduce
waiting without adding runners or changing the set of checks. The outcome will
be measured, including any slowdown, rather than inferred from a simulation.

## Scope

In scope: the existing selector, selected workflow wiring, duration weights,
PR concurrency, focused contract tests, paired observations and product docs.

Out of scope: selected matrix sharding, body-only recheck policy, Node runtime
support changes, shell-to-Node test migration, state or YAML format changes,
process supervision, canon changes and global caching. These remain explicit
follow-on slices under the parent RFC.

## Affected Area

The skill-suite GitHub Actions workflow and its existing suite-selection CLI.

## Desired Behavior (To-Be)

One selected runner retains four workers and all selected suites exactly once.
Measured weights determine queue order; unusable weights retain safe name order
with a diagnostic. Invalid suite input fails before framework execution.
Cancellation groups apply only to superseded verification for the same PR.

## Acceptance Criteria

- AC-001: Every discovered runnable suite has one positive integer weight,
  with measured provenance or explicitly labelled conservative fallback.
- AC-002: Selected names are unique, membership-preserving and sorted by
  descending weight with deterministic name ties.
- AC-003: Weight failures degrade visibly without dropping suites; invalid
  suite names and empty input fail before execution.
- AC-004: Real framework execution, aggregate gates, full-mode checks and
  carry-forward job identities retain their existing contracts.
- AC-005: Workflow configuration enables cancellation for the same PR while
  separating workflow/PR identity, non-PR runs and release workflows; local
  expression scenarios establish this configuration contract.
- AC-006: Five paired observations on a fixed workload report raw outcomes,
  runtime, median, worst time and runner-seconds, without invented timings or
  a promised global speedup.

The linked spec defines the exact TEST/Spec-AC mappings and the distinction
between local pre-PR evidence and hosted pre-merge follow-through.

## Verification

Use the canonical test wrapper for aai-suite-select and aai-ci-carry-forward,
the raw benchmark checker, scope-selected validation and hosted full regression.
Mandatory delivery checks H1 (hosted same-PR cancellation and successful
replacement, unrelated run unaffected) and H2 (candidate-SHA full regression
and existing platform jobs) run after PR creation and before merge. Local
acceptance permits normal implementation-doc close but does not assert H1/H2
or completed delivery. Keep both explicitly pending until observed and
independently verified; local assertions do not establish GitHub scheduling.

## Constraints / Risks

Keep dependency-free ESM, existing platform coverage, one selected runner,
four workers, conservative selection fallbacks and shipping-tree isolation.
No new secret reference is needed. Platform scheduling remains pending until
observed on the candidate PR. Source run data is historical evidence, not a
claim that a local benchmark predicts CI speedup.

## Notes

Authorized by the owner's /aai-ship invocation for the parent RFC. Planning
selected loop implementation with observed failing contract tests and an
independent validator/reviewer. The recommended worktree uses the ship
autopilot default. Owner intake time: one minute, recorded on the parent.

Remediation adds a bounded repair to product-doc TEST-012: preserve original
migration prose checks at a fixed historical boundary and permit subsequent
capability updates. The spec discloses incomplete historical per-row RED and
requires current timestamped scratch controls plus independent revalidation;
it does not claim new probes occurred before implementation. Integration now
uses main `35f1448410a3e9a813367a60defeb6551199db7f`; full final-tree checks and
H1/H2 remain required. The preliminary 108/109 sweep was cancelled at
`aai-sync-seed` TEST-790 with wrapper exit 143, not timeout or PASS.
