---
id: ci-body-only-rechecks
type: change
number: 217
status: done
links:
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Avoid repeated source validation on body-only PR edits

## Summary

Deliver the bounded RFC-0017 body-edit follow-on: updating a pull request's
body must run the checks that depend on that body without unnecessarily
repeating successful source regression for the identical validated inputs.

## Motivation / Business Value

The owner asked to continue reducing development/test time after the docs-audit
Node pilot. That ride exposed a concrete workflow loop: recording successful
CI evidence in the PR body triggered another complete framework matrix at the
same source head. PR 488 runs 39620558481 and 39621966528 both used source head
8ba67fa50bae02aa839d8233240150d44e6faf95; the second followed a body-only update.
Avoid this repeated work while preserving all meaningful validation and branch
protection contracts. Do not ask the owner to manage framework recovery.

## Scope

- In scope: classify body-only PR edits; distinguish body-dependent checks from
  reusable source evidence; conservatively integrate the decision into the
  existing skill-suite workflow and its stable gate; regression tests, hosted
  proof and concise existing documentation updates.
- Out of scope: broad local Validation-policy changes, migrating more Bash or
  PowerShell behavior, scheduler/shard redesign, cross-source test-result caches,
  changing branch protection and
  closing the umbrella RFC. Reducing redundant local full sweeps is the next
  separate slice; this child addresses the observed body-edit loop first.

## Affected Area

.github/workflows/skill-suite.yml and the existing Node CI decision helpers,
source-evidence queries and their test/selection wiring as required by Planning.
Prefer the existing implementation seam over a second parallel mechanism.

## Desired Behavior (To-Be)

An eligible body-only edit runs current-body checks and reports an explicit
reason for reusing already successful source validation. Eligibility must bind
to the actual PR and the validated source/base/workflow inputs; merely seeing
an edited event or a previously green unrelated run is insufficient. Unknown,
missing, failed, cancelled, in-flight, stale or untrusted evidence falls back
to the normal source-validation path. Source updates still receive their normal
regression checks. The owner sees actionable outcomes rather than framework
questions or silently skipped validation.

## Acceptance Criteria

- AC-001: For a proven body-only edit with eligible successful source evidence,
  the workflow executes body-dependent checks and its required aggregate gate,
  without launching the unchanged skill regression matrix or unrelated platform
  regression. Output names the decision, its reason and evidence identity.
- AC-002: Every body-dependent check, including release-note/exemption validation,
  evaluates the current PR body on every such edit. A body that violates those
  rules fails; reuse must never hide a current metadata failure.
- AC-003: New source, changed validation inputs, mixed/non-body edit events,
  missing/ambiguous evidence and unsuccessful or untrusted prior validation
  follow the normal conservative source-validation path. Existing non-edit
  behavior and meaningful regression coverage are preserved.
- AC-004: Required check names and branch-protection semantics remain compatible.
  No protection bypass, forged check status, assumed green result, source-wide
  cache or new dependency is introduced. New decision logic lives in Node with
  direct built-in tests where practical, rather than duplicated shell logic.
- AC-005: Independent negative controls cover false reuse and suppressed body
  failures. Hosted evidence demonstrates the normal source path and a body-only
  recheck at the same source head, with actual executed/skipped jobs and costs
  disclosed. Documentation accurately distinguishes eligibility, fallback and
  remaining limits; RFC-0017 remains open.

## Verification

Planning defines bounded direct Node tests, the necessary workflow/gate seam
checks and exact hosted proof. Preserve actual outputs and source identities.
Measure repeated work avoided (jobs/suites and observed runner time when
available), without inferring token savings or mixing different source trees.
Preserve all original failures and disclose infrastructure limitations.

## Constraints / Risks

Use the current Node/platform contract and built-in libraries. Keep decisions
small, deterministic where possible and fail safely to source validation on
uncertainty. Reuse only proof of the relevant inputs; PR/base/workflow changes
and untrusted evidence must not authorize a pass. Use canonical wrappers,
bounded workers and scoped cleanup. No local secret is referenced; existing CI
credential handling is unchanged and credential values must never be printed.
Preserve unrelated dirty INDEX content, old draft files and append-only ledgers.

## Notes

Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md.
Owner instruction: continue the proposed feedback-time improvements.
Autopilot defaults: human_time_minutes null, no metrics/mode question; Planning
chooses the implementation strategy and justifies validation scope. This is an
internal CI efficiency change. The owner explicitly directed merging PR 488
with "Sloučit PR #488 a uklidit (doporučeno)". It merged as
b2c00799dac6411e009a554124b12e8515c82363 and its checkout and branch were
cleaned before this child begins. That direction applies to PR 488 only.
