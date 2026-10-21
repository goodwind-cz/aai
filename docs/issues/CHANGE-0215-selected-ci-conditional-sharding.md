---
id: selected-ci-conditional-sharding
type: change
number: 215
status: done
capability: ci-test-impact-selection
user_visible: true
links:
  rfc: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  spec: docs/specs/SPEC-0240-spec-selected-ci-conditional-sharding.md
  pr:
    - 486
  commits: []
---

# Conditional sharding of selected CI suites

## Summary

Continue RFC-0017 after merged CHANGE-0214 / SPEC-0239 (#485): use at most
two selected runners when the existing measured weights predict enough wall
time saved within an explicit runner budget. Small or uncertain workloads
keep one runner. Every selected suite still runs exactly once.

## Motivation / Business Value

Longest-first ordering is already delivered. Large selected sets still share
one four-worker runner; reuse the existing shard representation and framework
to shorten that remaining queue without allocating four runners unconditionally.

## Scope

Selector planning, independent selected-plan validation, workflow execution and
aggregate gate wiring, carry-forward compatibility tests, measurements, product
documentation and release notes. No body-edit reuse, selection narrowing,
weight refresh, runtime baseline change, Node test migration, state/prompt
changes, cache or platform/process migration.

## Acceptance Criteria

- AC-001: The frozen spec defines deterministic one-versus-two runner eligibility
  from measured weights, conservative fallback and explicit predicted cost.
- AC-002: Selected plans preserve exactly the validated selected set; every
  consuming checkout independently checks it before execution.
- AC-003: One framework invocation per active runner retains four workers,
  isolation, failure propagation and the existing required gate identity.
- AC-004: Full runs, carry-forward anchor restrictions and cancellation retain
  their existing contracts.
- AC-005: Five paired real executions report wall time and runner-seconds;
  predicted savings are labelled estimates and hosted delivery is separately checked.

## Verification

The linked spec maps each acceptance criterion to executable tests and evidence.
Normal local validation precedes PR creation; hosted small/large selected cases
and full regression must be independently checked before merge-readiness.

## Constraints / Risks

Dependency-free Node, bash 3.2 compatibility, no reduced suite membership or
weakened isolation. Duration weights predict scheduling, not guaranteed hosted
latency; runner startup and queueing remain observable risks.

## Notes

Authorized continuation of the owner's /aai-ship RFC delivery. Planning chooses
loop with observed RED and independent validation/review. Use the existing
ship worktree authorization. The parent RFC remains open.
