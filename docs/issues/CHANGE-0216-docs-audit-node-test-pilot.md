---
id: docs-audit-node-test-pilot
type: change
number: 216
status: done
links:
  spec: spec-docs-audit-node-test-pilot
  pr: []
  commits: []
---

# Docs-audit Node test pilot

## Summary

Deliver a bounded RFC-0017 pilot that moves an explicitly mapped cluster of
pure docs-audit logic cases from the Bash skill suite to Node's built-in test
runner, and removes the replaced Bash cases rather than duplicating them.

## Motivation / Business Value

The owner wants less duplicated Bash/PowerShell code, faster development checks,
lower agent overhead and stable autonomous operation. Docs-audit production
logic already lives in Node modules, while its Bash suite has about 8,800 lines.
Pure logic tests should not pay for repeated CLI launches or repository setup.

## Scope

- In scope: select one coherent pure logic cluster, document its existing
  assertions, migrate them to dependency-free node:test, remove replaced Bash
  registrations/bodies, retain representative CLI and real-corpus checks,
  integrate the new tests into existing local/CI paths, measure before/after.
- Out of scope: migrating every docs-audit case, changing audit decisions or
  CLI contracts, weakening corpus/content checks, adding a second test
  framework, changing runtime support, sync/hook migration, PowerShell process
  adapters, PR-body evidence reuse, or closing the umbrella RFC.

## Affected Area

Docs-audit core/model functions, tests/skills/test-aai-docs-audit.sh, a focused
Node test file and the existing test-dispatch/selection wiring where needed.

## Desired Behavior (To-Be)

The migrated logic is tested directly through small in-memory inputs without
cloning the repository, Git initialization or child-process execution in the
fast logic path. Existing CLI/corpus behavior stays independently covered.
There is one authoritative home for every migrated assertion.

## Acceptance Criteria

- AC-001: A tracked migration map identifies every selected legacy case and
  semantic assertion, its Node replacement, and retained CLI/corpus coverage.
  The chosen cluster is justified before accepted timing samples are gathered.
- AC-002: The mapped assertions execute through node:test, including malformed
  inputs and positive controls; the fast logic path uses no repository clone,
  Git fixture or child process. No npm dependency is added.
- AC-003: Replaced Bash bodies and registrations are removed. All unmigrated
  cases and meaningful CLI/corpus checks remain reachable and keep their
  existing assertions. The new Node tests execute in the normal docs-audit
  local and CI path with failure propagation.
- AC-004: Five comparable before/after runs on the same runtime/hardware
  report sample count, median, worst duration and execution work. Measure both
  the matched logic workload and the remaining docs-audit suite as practical;
  disclose setup costs, skips and failures. The RFC target is a fast logic
  check within ten seconds; report the actual result without promising it.
- AC-005: Independent validation checks assertion preservation, an intentional
  defect or corruption that the migrated tests catch, integration wiring,
  corpus behavior and source isolation. Record actual Bash/Node line changes
  and preserved evidence. Product/engineering instructions name the fast and
  integration commands truthfully.

## Verification

Planning derives exact wrapper-based commands from the existing repository.
Verify focused Node cases, normal docs-audit suite dispatch, retained CLI/corpus
behavior, registration/isolation guards and relevant selected regression.
Measure equivalent workloads with at least five samples and preserve raw logs.

## Constraints / Risks

Preserve the current Node/platform support contract and Bash 3.2 compatibility.
Use only Node built-ins; keep independent tests from mirroring implementation.
Do not mutate the shipping checkout while testing; use the canonical wrapper,
bounded workers and scoped reaper. Preserve unrelated local drafts and ledgers.
No local secret is referenced. A smaller Bash file alone is not evidence of a
faster or equally strong test suite.

## Notes

Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md, phase 2.
Scheduling foundations and conditional selected sharding merged as PRs 485/486.
The owner explicitly asked to proceed with this docs-audit migration now.
Autopilot defaults: no intake metrics question, human_time_minutes null;
implementation strategy is left to Planning. Scope is internal test/refactor
work; no public capability or runtime baseline change is requested.

Implementation spec: [Body-lint Node test pilot](../specs/SPEC-0241-spec-docs-audit-node-test-pilot.md).
